# Privacy

Timestamp Only is local-only. The application does not contain telemetry, analytics, advertising, upload code, update-check code, or client/server network entitlements.

## Data the app accesses

For direct children of the folder you select, Timestamp Only may read:

- The filename, extension, and file identity
- File size, modification time, and creation time
- Uniform type information supplied by macOS
- Apple's screen-capture and screen-recording metadata markers
- A content-creation date supplied by macOS metadata when file creation time is unavailable

The app does not open or decode image or PDF content. It uses metadata to decide whether a file is a newly created Apple still screenshot, then asks the filesystem to rename that directory entry in place.

The screen-capture marker used by macOS is an implementation detail rather than a documented public contract. Timestamp Only isolates that detector and fails closed: missing, unreadable, or unrecognized metadata never makes an unrelated file eligible merely because its name or extension looks like a screenshot.

## Data the app stores

The sandbox container stores the selected filename format, local-time or UTC choice, pause state, launch-at-login request, settings schema version, and a security-scoped bookmark for the chosen folder. No screenshot history, file content, account identifier, database, or Keychain item is required.

Unified logging marks filenames as private. The Settings window may display the selected folder and the latest renamed filename to the signed-in user, but the app does not retain a rename history.

## Permissions

The app has these sandbox entitlements:

- App Sandbox
- User-selected files, read/write
- App-scoped security-scoped bookmarks

It does not request Full Disk Access, Screen Recording, Accessibility, Automation, camera, microphone, or network access. Apple explains that an AppKit `NSOpenPanel` extends a sandbox to a user-selected URL and that a stored security-scoped bookmark can preserve that choice across launches in [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

## Privacy manifest

The app bundle contains `PrivacyInfo.xcprivacy`, declares no collected data and no tracking, and describes its use of file timestamps and app-private user defaults. The file timestamp reason `3B52.1` covers metadata of files or directories the user specifically granted access to, and `CA92.1` covers preferences accessible only to the app. See Apple's [approved required-reason values](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) and [privacy-manifest placement rules](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).
