# Timestamp Only

Timestamp Only is a small, local-only macOS menu-bar utility that replaces Apple's verbose screenshot filenames with concise timestamp names such as `2026-09-04 13.05.09.png`.

The app is designed to be installed once and forgotten: choose the folder where macOS saves screenshots, optionally enable launch at login, and use the menu-bar icon whenever you need to pause, resume, or change settings.

## What it does

- Renames only newly created files carrying Apple's positive screen-capture metadata
- Works independently of the localized or customized original filename
- Preserves the original extension, including non-PNG still-image formats and PDF
- Uses file creation time by default, with metadata and observation-time fallbacks
- Supports local time or UTC and a customizable date format with a live preview
- Resolves collisions with `-1`, `-2`, and later suffixes without overwriting anything
- Waits for files to stabilize and deduplicates repeated filesystem events
- Excludes screen recordings

Timestamp Only does not inspect image content, upload files, collect telemetry, or make network connections. It requests read/write access only to the folder you choose.

## Release safety

Only artifacts published on the repository's Releases page through the guarded maintainer workflow are Developer ID signed and notarized for redistribution. Development builds are ad-hoc signed and are not suitable for redistribution.

The deployment target is macOS 11, and release builds contain native arm64 and x86_64 code. Big Sur and Monterey remain release qualification gates until the complete app, security-scoped bookmark, and embedded login-item fallback have been exercised on those systems. See [design and compatibility](docs/DESIGN.md#compatibility).

## Build from source

Building requires macOS, Xcode command-line tools, and Swift Package Manager.

```sh
make check
make check-app
make check-dmg
```

All filesystem integration tests use self-created temporary directories. Do not point development builds at a real screenshot folder.

The assembled development app is written to `build/Timestamp Only.app`. Development targets use ad-hoc signing and their output must not be distributed. The guarded local release workflow creates a separate Developer ID-signed and notarized candidate under the ignored `release-candidates/` directory; see [Release process](docs/RELEASE.md).

Public releases use numeric SemVer from `VERSION` and a separate monotonically increasing integer build from `BUILD_NUMBER`. The DMG uses the stable name `Timestamp-Only-<version>.dmg` and is accompanied by a SHA-256 checksum suitable for direct distribution and a future Homebrew Cask.

CI runs the source checks natively on Apple silicon and Intel hosted runners, then assembles and verifies the universal app and DMG. Hosted CI does not substitute for runtime qualification on macOS 11 and 12.

## Documentation

- [Installation, first run, and updates](docs/INSTALL.md)
- [Settings](docs/SETTINGS.md)
- [Privacy](docs/PRIVACY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Complete removal](docs/UNINSTALL.md)
- [Design and compatibility](docs/DESIGN.md)
- [Release process](docs/RELEASE.md)

## License

Timestamp Only is licensed under [AGPL-3.0-only](LICENSE).
